import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import 'reference_controller.dart';

class ReferenceScreen extends ConsumerWidget {
  const ReferenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(referenceControllerProvider);
    final ctrl = ref.read(referenceControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify by reference')),
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
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (state.result != null) ...[
            const SizedBox(height: 16),
            _ResultCard(result: state.result!),
          ],
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
    Color badge;
    switch (result.status) {
      case 'SUCCESS':
        badge = Colors.green;
        break;
      case 'FAILED':
        badge = Colors.red;
        break;
      default:
        badge = Colors.orange;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badge.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badge),
                  ),
                  child: Text(
                    result.status,
                    style: TextStyle(color: badge, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.reference ?? '-',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Amount: ${result.amount?.toStringAsFixed(2) ?? '-'}'),
            Text('Payer: ${result.payer ?? '-'}'),
            Text('Date: ${result.date ?? '-'}'),
          ],
        ),
      ),
    );
  }
}
