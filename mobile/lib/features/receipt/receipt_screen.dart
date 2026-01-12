import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/models.dart';
import 'receipt_controller.dart';

class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiptControllerProvider);
    final ctrl = ref.read(receiptControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify by receipt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          if (ctrl.supportsUploadFallback)
            FilledButton.icon(
              onPressed: state.isLoading ? null : ctrl.uploadFallback,
              icon: const Icon(Icons.cloud_upload),
              label: Text(state.isLoading ? 'Working…' : 'Upload fallback'),
            )
          else
            const Text('Upload fallback is available for CBE/Telebirr only.'),
          const SizedBox(height: 12),
          if (state.extractedReference != null)
            Text('OCR extracted reference: ${state.extractedReference}'),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (state.result != null) ...[
            const SizedBox(height: 12),
            _ResultCard(result: state.result!),
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
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final NormalizedVerification result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${result.status}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Reference: ${result.reference ?? '-'}'),
            Text('Amount: ${result.amount?.toStringAsFixed(2) ?? '-'}'),
            Text('Payer: ${result.payer ?? '-'}'),
            Text('Date: ${result.date ?? '-'}'),
          ],
        ),
      ),
    );
  }
}
