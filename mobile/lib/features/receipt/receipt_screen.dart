import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/models.dart';
import '../common/verification_result_view.dart';
import 'receipt_controller.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  late final TextEditingController _refController;

  @override
  void initState() {
    super.initState();
    _refController = TextEditingController();
  }

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiptControllerProvider);
    final ctrl = ref.read(receiptControllerProvider.notifier);

    final extracted = state.extractedReference;
    if (extracted != null && extracted != _refController.text) {
      // Keep text field in sync when OCR updates.
      _refController.value = TextEditingValue(
        text: extracted,
        selection: TextSelection.collapsed(offset: extracted.length),
      );
    }

    final suggestedProvider = _suggestProvider(extracted);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify by receipt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.isLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'OCR/verification can take a while. If it feels stuck, tap Cancel and try again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          if (state.isLoading) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: ctrl.cancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<PaymentProvider>(
            initialValue: state.provider,
            items: PaymentProvider.values
                .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (p) {
              if (p != null) ctrl.setProvider(p);
            },
            decoration: const InputDecoration(labelText: 'Provider'),
          ),
          if (ctrl.needsSuffix) ...[
            const SizedBox(height: 12),
            TextFormField(
              initialValue: state.suffix,
              onChanged: ctrl.setSuffix,
              decoration: const InputDecoration(
                labelText: 'Account suffix (CBE)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isLoading
                      ? null
                      : () async {
                          final picker = ImagePicker();
                          final img = await picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 85,
                          );
                          if (img != null) await ctrl.setImagePath(img.path);
                        },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isLoading
                      ? null
                      : () async {
                          final picker = ImagePicker();
                          final img = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (img != null) await ctrl.setImagePath(img.path);
                        },
                  icon: const Icon(Icons.photo),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.imagePath != null) Text('Selected: ${state.imagePath}'),
          const SizedBox(height: 8),
          if (state.imagePath == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Pick a receipt photo. The app will run OCR and auto-verify when it can.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (ctrl.supportsUploadFallback)
            FilledButton.icon(
              onPressed: state.isLoading ? null : ctrl.uploadFallback,
              icon: const Icon(Icons.cloud_upload),
              label: Text(state.isLoading ? 'Working…' : 'Upload fallback'),
            )
          else
            const Text('Upload fallback is available for CBE/Telebirr only.'),
          const SizedBox(height: 12),
          if (extracted != null) ...[
            TextFormField(
              controller: _refController,
              decoration: const InputDecoration(
                labelText: 'Extracted reference (edit if needed)',
              ),
              onChanged: ctrl.setExtractedReference,
            ),
            const SizedBox(height: 8),
            if (suggestedProvider != null &&
                suggestedProvider != state.provider)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.tips_and_updates_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This reference looks like ${suggestedProvider.label}. Switch provider?',
                        ),
                      ),
                      TextButton(
                        onPressed: state.isLoading
                            ? null
                            : () => ctrl.setProvider(suggestedProvider),
                        child: const Text('Switch'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.isLoading
                  ? null
                  : ctrl.verifyByExtractedReference,
              icon: const Icon(Icons.verified),
              label: Text(
                state.isLoading ? 'Verifying…' : 'Verify extracted reference',
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    state.isLoading || state.imagePath == null
                                    ? null
                                    : ctrl.runOcrAndTryVerify,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry OCR'),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    state.isLoading ||
                                        state.extractedReference == null ||
                                        state.extractedReference!.isEmpty
                                    ? null
                                    : ctrl.verifyByExtractedReference,
                                icon: const Icon(Icons.verified),
                                label: const Text('Retry verify'),
                              ),
                              if (ctrl.supportsUploadFallback)
                                OutlinedButton.icon(
                                  onPressed:
                                      state.isLoading || state.imagePath == null
                                      ? null
                                      : ctrl.uploadFallback,
                                  icon: const Icon(Icons.cloud_upload),
                                  label: const Text('Retry upload'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (state.result != null) ...[
            const SizedBox(height: 12),
            VerificationResultView(
              result: state.result!,
              fallbackProvider: state.provider,
              onRetry: state.isLoading
                  ? null
                  : () {
                      if (state.extractedReference != null &&
                          state.extractedReference!.trim().isNotEmpty) {
                        ctrl.verifyByExtractedReference();
                        return;
                      }
                      if (ctrl.supportsUploadFallback &&
                          state.imagePath != null) {
                        ctrl.uploadFallback();
                      }
                    },
            ),
          ],
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('OCR text (debug)'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(state.ocrText ?? '-'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PaymentProvider? _suggestProvider(String? ref) {
    if (ref == null) return null;
    final v = ref.trim().toUpperCase();
    if (v.startsWith('BB')) return PaymentProvider.telebirr;
    if (RegExp(r'^\d{3}FTO\d{6,}$').hasMatch(v)) return PaymentProvider.dashen;
    return null;
  }
}
