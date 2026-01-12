import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/di/providers.dart';
import '../../core/storage/history_store.dart';

class ReferenceState {
  const ReferenceState({
    required this.provider,
    this.reference = '',
    this.suffix = '',
    this.phone = '',
    this.isLoading = false,
    this.error,
    this.result,
  });

  final PaymentProvider provider;
  final String reference;
  final String suffix;
  final String phone;
  final bool isLoading;
  final String? error;
  final NormalizedVerification? result;

  ReferenceState copyWith({
    PaymentProvider? provider,
    String? reference,
    String? suffix,
    String? phone,
    bool? isLoading,
    String? error,
    NormalizedVerification? result,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return ReferenceState(
      provider: provider ?? this.provider,
      reference: reference ?? this.reference,
      suffix: suffix ?? this.suffix,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

class ReferenceController extends Notifier<ReferenceState> {
  @override
  ReferenceState build() {
    return const ReferenceState(provider: PaymentProvider.telebirr);
  }

  ApiClient get _api => ref.read(apiClientProvider);
  HistoryStore get _history => ref.read(historyStoreProvider);

  void setProvider(PaymentProvider p) => state = state.copyWith(provider: p);
  void setReference(String v) => state = state.copyWith(reference: v);
  void setSuffix(String v) => state = state.copyWith(suffix: v);
  void setPhone(String v) => state = state.copyWith(phone: v);

  bool get needsSuffix =>
      state.provider == PaymentProvider.cbe ||
      state.provider == PaymentProvider.abyssinia;
  bool get needsPhone => state.provider == PaymentProvider.cbebirr;

  Future<void> verify() async {
    final ref = state.reference.trim();
    if (ref.isEmpty) {
      state = state.copyWith(error: 'Enter a reference', clearResult: true);
      return;
    }
    if (needsSuffix && state.suffix.trim().isEmpty) {
      state = state.copyWith(
        error: 'Suffix is required for this provider',
        clearResult: true,
      );
      return;
    }
    if (needsPhone && state.phone.trim().isEmpty) {
      state = state.copyWith(
        error: 'Phone is required for CBE Birr',
        clearResult: true,
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.verifyReference(
        provider: state.provider,
        reference: ref,
        suffix: state.suffix.trim().isEmpty ? null : state.suffix.trim(),
        phone: state.phone.trim().isEmpty ? null : state.phone.trim(),
      );
      state = state.copyWith(isLoading: false, result: res);

      await _history.add({
        'ts': DateTime.now().toIso8601String(),
        'type': 'reference',
        'provider': state.provider.value,
        'reference': ref,
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

final referenceControllerProvider =
    NotifierProvider<ReferenceController, ReferenceState>(
      ReferenceController.new,
    );
