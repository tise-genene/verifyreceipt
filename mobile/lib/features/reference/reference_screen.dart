import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../common/verification_result_view.dart';
import '../settings/server_settings_screen.dart';
import 'reference_controller.dart';

class ReferenceScreen extends ConsumerWidget {
  const ReferenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(referenceControllerProvider);
    final ctrl = ref.read(referenceControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify by reference'),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.isLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Some providers can take up to ~90 seconds. If it feels stuck, tap Cancel and Retry.',
              style: Theme.of(context).textTheme.bodySmall,
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
          const SizedBox(height: 12),
          TextFormField(
            initialValue: state.reference,
            onChanged: ctrl.setReference,
            decoration: const InputDecoration(
              labelText: 'Reference',
              hintText: 'e.g. FT25361BLWRM',
            ),
          ),
          if (ctrl.needsSuffix) ...[
            const SizedBox(height: 12),
            TextFormField(
              initialValue: state.suffix,
              onChanged: ctrl.setSuffix,
              decoration: const InputDecoration(labelText: 'Account suffix'),
            ),
          ],
          if (ctrl.needsPhone) ...[
            const SizedBox(height: 12),
            TextFormField(
              initialValue: state.phone,
              onChanged: ctrl.setPhone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: state.isLoading ? null : ctrl.verify,
            icon: const Icon(Icons.verified),
            label: Text(state.isLoading ? 'Verifying…' : 'Verify'),
          ),
          if (state.isLoading) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: ctrl.cancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
          ],
          const SizedBox(height: 12),
          if (state.error != null)
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
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: state.isLoading ? null : ctrl.verify,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (state.result == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Enter a reference and tap Verify.\nTip: try the Scan tab for QR codes.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          if (state.result != null) ...[
            const SizedBox(height: 12),
            VerificationResultView(
              result: state.result!,
              fallbackProvider: state.provider,
              onRetry: state.isLoading ? null : ctrl.verify,
            ),
          ],
        ],
      ),
    );
  }
}
