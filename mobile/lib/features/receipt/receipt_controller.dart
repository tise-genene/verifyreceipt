import 'dart:io';

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
  @override
  ReceiptState build() {
    return const ReceiptState(provider: PaymentProvider.telebirr);
  }

  ApiClient get _api => ref.read(apiClientProvider);
  OcrService get _ocr => ref.read(ocrServiceProvider);
  HistoryStore get _history => ref.read(historyStoreProvider);

  void setProvider(PaymentProvider p) => state = state.copyWith(provider: p);
  void setSuffix(String v) => state = state.copyWith(suffix: v);

  bool get needsSuffix => state.provider == PaymentProvider.cbe;

  bool get supportsUploadFallback =>
      state.provider == PaymentProvider.cbe ||
      state.provider == PaymentProvider.telebirr;

  Future<void> setImagePath(String path) async {
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

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final text = await _ocr.recognizeTextFromPath(path);
      final ref = extractReference(text);

      state = state.copyWith(
        isLoading: false,
        ocrText: text,
        extractedReference: ref,
      );

      if (ref != null && ref.isNotEmpty) {
        await verifyByExtractedReference();
      }
    } catch (e) {
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

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.verifyReference(
        provider: state.provider,
        reference: ref.trim(),
        suffix: needsSuffix ? state.suffix.trim() : null,
      );
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
      });
    } catch (e) {
      // OCR path failed: allow upload fallback.
      state = state.copyWith(
        isLoading: false,
        error: errorMessage(e),
        clearResult: true,
      );
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

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.verifyReceipt(
        provider: state.provider,
        imageFile: File(path),
        suffix: needsSuffix ? state.suffix.trim() : null,
      );
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
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: errorMessage(e),
        clearResult: true,
      );
    }
  }
}

final receiptControllerProvider =
    NotifierProvider<ReceiptController, ReceiptState>(ReceiptController.new);
