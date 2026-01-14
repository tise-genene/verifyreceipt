import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/di/providers.dart';
import '../../core/ocr/ocr_service.dart';
import '../../core/ocr/receipt_parser.dart';
import '../../core/storage/history_store.dart';

class ReceiptState {
  const ReceiptState({
    required this.provider,
    this.suffix = '',
    this.imagePath,
    this.ocrText,
    this.extractedReference,
    this.isLoading = false,
    this.error,
    this.result,
  });

  final PaymentProvider provider;
  final String suffix;
  final String? imagePath;
  final String? ocrText;
  final String? extractedReference;
  final bool isLoading;
  final String? error;
  final NormalizedVerification? result;

  ReceiptState copyWith({
    PaymentProvider? provider,
    String? suffix,
    String? imagePath,
    String? ocrText,
    String? extractedReference,
    bool? isLoading,
    String? error,
    NormalizedVerification? result,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return ReceiptState(
      provider: provider ?? this.provider,
      suffix: suffix ?? this.suffix,
      imagePath: imagePath ?? this.imagePath,
      ocrText: ocrText ?? this.ocrText,
      extractedReference: extractedReference ?? this.extractedReference,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

class ReceiptController extends Notifier<ReceiptState> {
  CancelToken? _cancelToken;
  int _opId = 0;

  @override
  ReceiptState build() {
    return const ReceiptState(provider: PaymentProvider.telebirr);
  }

  ApiClient get _api => ref.read(apiClientProvider);
  OcrService get _ocr => ref.read(ocrServiceProvider);
  HistoryStore get _history => ref.read(historyStoreProvider);

  void setProvider(PaymentProvider p) =>
      state = state.copyWith(provider: p, clearError: true, clearResult: true);
  void setSuffix(String v) =>
      state = state.copyWith(suffix: v, clearError: true, clearResult: true);

  void setExtractedReference(String v) => state = state.copyWith(
    extractedReference: v,
    clearError: true,
    clearResult: true,
  );

  bool get needsSuffix => state.provider == PaymentProvider.cbe;

  bool get supportsUploadFallback =>
      state.provider == PaymentProvider.cbe ||
      state.provider == PaymentProvider.telebirr;

  void cancel() {
    _opId++;
    _cancelToken?.cancel('user_cancelled');
    _cancelToken = null;
    if (state.isLoading) {
      state = state.copyWith(isLoading: false, error: 'Cancelled.');
    }
  }

  Future<void> setImagePath(String path) async {
    _opId++;
    state = state.copyWith(
      imagePath: path,
      ocrText: null,
      extractedReference: null,
      clearError: true,
      clearResult: true,
    );

    await runOcrAndTryVerify();
  }

  Future<void> runOcrAndTryVerify() async {
    final path = state.imagePath;
    if (path == null) return;

    final myOp = ++_opId;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final text = await _ocr.recognizeTextFromPath(path);
      final ref = extractReference(text);

      if (myOp != _opId) return;

      state = state.copyWith(
        isLoading: false,
        ocrText: text,
        extractedReference: ref,
      );

      if (ref != null && ref.isNotEmpty) {
        await verifyByExtractedReference();
      }
    } catch (e) {
      if (myOp != _opId) return;
      state = state.copyWith(isLoading: false, error: errorMessage(e));
    }
  }

  Future<void> verifyByExtractedReference() async {
    final ref = state.extractedReference;
    if (ref == null || ref.trim().isEmpty) {
      state = state.copyWith(error: 'Could not extract a reference from OCR');
      return;
    }
    if (needsSuffix && state.suffix.trim().isEmpty) {
      state = state.copyWith(error: 'Suffix is required for CBE');
      return;
    }

    _cancelToken?.cancel('superseded');
    _cancelToken = CancelToken();
    final myOp = ++_opId;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.verifyReference(
        provider: state.provider,
        reference: ref.trim(),
        suffix: needsSuffix ? state.suffix.trim() : null,
        cancelToken: _cancelToken,
      );
      if (myOp != _opId) return;
      state = state.copyWith(isLoading: false, result: res);

      await _history.add({
        'ts': DateTime.now().toIso8601String(),
        'type': 'receipt_ocr_ref',
        'provider': state.provider.value,
        'reference': ref.trim(),
        'status': res.status,
        'amount': res.amount,
        'payer': res.payer,
        'date': res.date,
        'raw': res.raw,
      });
    } catch (e) {
      // OCR path failed: allow upload fallback.
      if (myOp != _opId) return;
      state = state.copyWith(
        isLoading: false,
        error: errorMessage(e),
        clearResult: true,
      );
    } finally {
      _cancelToken = null;
    }
  }

  Future<void> uploadFallback() async {
    if (!supportsUploadFallback) {
      state = state.copyWith(
        error:
            'Upload fallback is only supported for CBE and Telebirr receipts',
        clearResult: true,
      );
      return;
    }
    final path = state.imagePath;
    if (path == null) {
      state = state.copyWith(error: 'Pick a receipt image first');
      return;
    }
    if (needsSuffix && state.suffix.trim().isEmpty) {
      state = state.copyWith(error: 'Suffix is required for CBE upload');
      return;
    }

    _cancelToken?.cancel('superseded');
    _cancelToken = CancelToken();
    final myOp = ++_opId;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.verifyReceipt(
        provider: state.provider,
        imageFile: File(path),
        suffix: needsSuffix ? state.suffix.trim() : null,
        cancelToken: _cancelToken,
      );
      if (myOp != _opId) return;
      state = state.copyWith(isLoading: false, result: res);

      await _history.add({
        'ts': DateTime.now().toIso8601String(),
        'type': 'receipt_upload',
        'provider': state.provider.value,
        'reference': res.reference,
        'status': res.status,
        'amount': res.amount,
        'payer': res.payer,
        'date': res.date,
        'raw': res.raw,
      });
    } catch (e) {
      if (myOp != _opId) return;
      state = state.copyWith(
        isLoading: false,
        error: errorMessage(e),
        clearResult: true,
      );
    } finally {
      _cancelToken = null;
    }
  }
}

final receiptControllerProvider =
    NotifierProvider<ReceiptController, ReceiptState>(ReceiptController.new);
